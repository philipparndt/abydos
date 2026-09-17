import AppKit
import AbydosKit

/// Renders Markdown to an attributed string for the preview pane.
///
/// Uses Foundation's CommonMark parser rather than a web view: the preview then
/// costs no WebKit process, no HTML round-trip, and renders with the same text
/// stack as everything else in the window.
///
/// Foundation gives structure (`PresentationIntent`) but no appearance, so the
/// block styling below is what turns intents into something readable.
@MainActor
enum MarkdownRenderer {
	/// The proportions this render is set in.
	///
	/// Read at the start of every render rather than stored, because the body
	/// follows the zoom: `bodySize` was a constant for as long as the preview
	/// existed, and ⌘+ grew the tree, the tabs and the editor beside it while
	/// the page stayed at 13.5 points. Static because every function in here
	/// is, and the renderer is main-actor and never re-entered.
	private static var type = MarkdownTypography(body: 14)

	/// The body a page is set at, before the zoom: fourteen rather than a
	/// browser's sixteen, because this is a pane beside an editor and not a
	/// page on its own.
	static let pageBody: Double = 14

	/// The inset a page's text view gives its text, at the zoom in force.
	static var pageInset: NSSize {
		let type = MarkdownTypography(body: Theme.current.scaled(pageBody))
		return NSSize(width: type.insetX, height: type.insetY)
	}

	/// - Parameter body: the body size to set the page at, already scaled;
	///   the page's own when nil. The commit-message pane passes its column's.
	static func render(_ markdown: String, baseURL: URL?, body: Double? = nil) -> NSAttributedString {
		type = MarkdownTypography(body: body ?? Theme.current.scaled(pageBody))
		quoteBlocks = [:]
		markedListItems = []

		let output = NSMutableAttributedString()

		// A ```mermaid fence comes out first, before anything is parsed. It has to
		// be first rather than merely somewhere: a diagram's own lines look like
		// other things — `|` rows read as a pipe table, `%%` and `#` as headings —
		// and every pass below would otherwise take a bite out of the picture.
		for piece in MarkdownFence.split(markdown) {
			switch piece {
			case let .drawn(fence):
				startParagraph(output)
				output.append(renderDiagram(fence))
			case let .prose(text):
				startParagraph(output)
				output.append(renderProse(text, baseURL: baseURL))
			}
		}

		// A page that ends in a newline has an empty paragraph after it, and an
		// empty paragraph is laid out in the style of the character before it:
		// after a fence, that was an empty line of panel under the code.
		trimTrailingNewlines(output)
		return output
	}

	/// The prose between the pictures, which is everything this rendered before.
	private static func renderProse(_ markdown: String, baseURL: URL?) -> NSAttributedString {
		let output = NSMutableAttributedString()

		// Foundation's parser does not understand GFM pipe tables — they arrive
		// as ordinary paragraphs with the bars intact, which reads as mangled
		// prose. They are pulled out first and laid out as a real table.
		for block in splitOutTables(markdown) {
			// Whatever comes next begins a paragraph of its own: a paragraph takes
			// the style of its first character, so a cell appended to an
			// unterminated heading joins that heading instead of opening the grid
			// — which put "file" beside "The diagrams" and shifted every column
			// one to the left.
			startParagraph(output)
			switch block {
			case let .table(text):
				output.append(renderTable(text, baseURL: baseURL))
			case let .markdown(text):
				output.append(renderBlocks(text, baseURL: baseURL))
			}
		}
		return output
	}

	/// Whatever comes next has to begin a paragraph of its own.
	private static func startParagraph(_ output: NSMutableAttributedString) {
		guard output.length > 0, !output.string.hasSuffix("\n") else { return }
		output.append(NSAttributedString(string: "\n"))
	}

	// MARK: - Fonts and colours

	private static var bodyFont: NSFont { Theme.font(size: type.body, weight: .regular, monospaced: false) }
	private static var monoFont: NSFont { Theme.font(size: type.code, weight: .regular, monospaced: true) }

	private static func headingFont(level: Int) -> NSFont {
		Theme.font(size: type.heading(level), weight: .semibold, monospaced: false)
	}

	/// The surface code sits on: the theme's own current-line colour, which is
	/// the one ground every theme already made for coloured code, a step off
	/// the page in the direction of the text. See `MarkdownTypography`.
	private static var panelColour: NSColor { Theme.current.currentLineBackground }

	/// Text that recedes: a quote, a level-six heading, a line under a diagram.
	private static var dimText: NSColor { Theme.current.gutterText }

	/// The spacing that sets `font` on a line `height` tall, top to top —
	/// added under the glyphs rather than as a fixed line height, which TextKit
	/// pads above them and which would have put every first line low in its box.
	private static func lineSpacing(for font: NSFont, height: Double) -> CGFloat {
		let natural = font.ascender - font.descender + font.leading
		return max(0, CGFloat(height) - natural)
	}

	/// The paragraph style prose is set in.
	private static func bodyParagraph() -> NSMutableParagraphStyle {
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineSpacing = lineSpacing(for: bodyFont, height: type.lineHeight)
		paragraph.paragraphSpacing = type.paragraphSpacing
		return paragraph
	}

	// MARK: - Block rendering

	private static func renderBlocks(_ markdown: String, baseURL: URL?) -> NSAttributedString {
		let output = NSMutableAttributedString()

		var options = AttributedString.MarkdownParsingOptions()
		// Preserve block structure; the default flattens everything to one run.
		options.interpretedSyntax = .full
		options.failurePolicy = .returnPartiallyParsedIfPossible
		options.allowsExtendedAttributes = true

		// Foundation flattens a link's label and lets a stray `~` eat the
		// emphasis around it. Neither is reachable through the options above, so
		// the parser is handed a repaired copy — of this string, never of the
		// file or of what is in the editor. See `MarkdownSource`.
		let source = MarkdownSource.repaired(markdown)

		guard let parsed = try? AttributedString(markdown: source, options: options, baseURL: baseURL) else {
			// Even unparseable input should still be readable.
			return NSAttributedString(string: markdown, attributes: [
				.font: bodyFont,
				.foregroundColor: Theme.current.editorText,
				.paragraphStyle: bodyParagraph(),
			])
		}

		// Runs carrying the same intent identity belong to the same block.
		var previousBlockID: [Int]?

		let runs = Array(parsed.runs)
		var index = 0
		while index < runs.count {
			let run = runs[index]
			let intent = run.presentationIntent
			let blockID = intent?.components.map(\.identity)

			// A fenced block is one block whatever its language: a string or a
			// comment can span lines, and colouring one run at a time would end
			// them at every newline — and a fence with no language used to go
			// through the paragraph path below, where every line of it ended a
			// paragraph and took the body's spacing after it.
			if let fence = Self.fence(of: intent) {
				var text = String(parsed[run.range].characters)
				var next = index + 1
				while next < runs.count,
				      runs[next].presentationIntent?.components.map(\.identity) == blockID {
					text += String(parsed[runs[next].range].characters)
					next += 1
				}
				startParagraph(output)
				previousBlockID = blockID
				output.append(codeBlock(text, languageId: fence.language, inside: quoteBlock(of: intent)))
				index = next
				continue
			}

			// A picture, where the parser left only its words. Foundation turns
			// `![alt](path)` into the alt text carrying `imageURL` and draws
			// nothing, so a document's screenshots were sentences in the preview
			// — found when a picture pasted into a document rendered as its own
			// description. The same cell a diagram sits in, so a screenshot wider
			// than the pane shrinks to it. A picture that is not on disk stays as
			// its words, which is what a broken reference should look like.
			if let imageURL = run.imageURL, let image = Self.picture(at: imageURL) {
				startParagraph(output)
				previousBlockID = blockID
				output.append(picture(image, paper: .clear))
				index += 1
				continue
			}

			index += 1
			let text = String(parsed[run.range].characters)

			// A block's marker belongs on its first run only. Inline styling
			// splits a list item into several runs, so applying it per run
			// sprinkles bullets through the middle of sentences.
			let isBlockStart = previousBlockID != blockID
			if isBlockStart { startParagraph(output) }
			previousBlockID = blockID

			// Whether the next block is still in this list decides the spacing
			// under an item: items sit close, and the last one opens up to a
			// paragraph's worth before whatever follows the list.
			var nextIntent: PresentationIntent?
			if Self.isListItem(intent) {
				var peek = index
				while peek < runs.count, runs[peek].presentationIntent?.components.map(\.identity) == blockID {
					peek += 1
				}
				nextIntent = peek < runs.count ? runs[peek].presentationIntent : nil
			}

			append(styled(text: text, run: run, intent: intent, next: nextIntent, isBlockStart: isBlockStart), to: output)
		}

		return output
	}

	/// Appends a run, kerning the letter before a pill so the paint has room.
	private static func append(_ run: NSAttributedString, to output: NSMutableAttributedString) {
		if run.length > 0, output.length > 0,
		   run.attribute(.abydosInlineCode, at: 0, effectiveRange: nil) is MarkdownPill,
		   !output.string.hasSuffix("\n") {
			output.addAttribute(.kern, value: type.pillPaddingX, range: NSRange(location: output.length - 1, length: 1))
		}
		output.append(run)
	}

	/// The fence a block is, and the language it names when a grammar is loaded
	/// for it — nil for no fence, `(nil)` for a fence set as plain code.
	private static func fence(of intent: PresentationIntent?) -> (language: String?, Void)? {
		for component in intent?.components ?? [] {
			guard case let .codeBlock(hint) = component.kind else { continue }
			return (hint.flatMap { LanguageRegistry.shared.languageId(forFenceInfo: $0) }, ())
		}
		return nil
	}

	private static func isList(_ kind: PresentationIntent.Kind) -> Bool {
		switch kind {
		case .orderedList, .unorderedList: return true
		default: return false
		}
	}

	private static func isListItem(_ intent: PresentationIntent?) -> Bool {
		intent?.components.contains { if case .listItem = $0.kind { return true }; return false } ?? false
	}

	/// A code block: one panel around every line of it, coloured by its grammar
	/// when it has one and in the text colour when it has not.
	///
	/// The lines share one `NSTextBlock`, which is what makes them one block to
	/// the text system; inside it there is no paragraph spacing, only the code's
	/// own line height. The eight points that used to sit under every line were
	/// the body paragraph's spacing leaking into code.
	private static func codeBlock(
		_ text: String, languageId: String? = nil, inside quote: NSTextBlock? = nil
	) -> NSMutableAttributedString {
		let panel = MarkdownPanelBlock(colour: panelColour, radius: type.cornerRadius)
		spanTheColumn(panel)
		let spacing = lineSpacing(for: monoFont, height: type.codeLineHeight)
		panel.setWidth(type.panelPadding, type: .absoluteValueType, for: .padding)
		// The last line carries its line spacing under it, inside the panel, so
		// the padding below gives that much back and the panel sits even.
		panel.setWidth(max(0, type.panelPadding - spacing), type: .absoluteValueType, for: .padding, edge: .maxY)
		panel.setWidth(type.paragraphSpacing, type: .absoluteValueType, for: .margin, edge: .maxY)

		let paragraph = NSMutableParagraphStyle()
		paragraph.textBlocks = [quote, panel].compactMap { $0 }
		paragraph.lineSpacing = spacing
		paragraph.paragraphSpacing = 0

		// The block's last line ends with the one newline that closes it, and
		// no more: a trailing blank line in the source would be a blank line of
		// panel under the code.
		var code = text
		while code.hasSuffix("\n") { code.removeLast() }
		code += "\n"

		let output = NSMutableAttributedString(string: code, attributes: [
			.font: monoFont,
			.foregroundColor: Theme.current.editorText,
			.paragraphStyle: paragraph,
		])

		guard let languageId, let engine = SyntaxEngine(languageId: languageId) else { return output }
		let rope = Rope(code)
		engine.parse(rope: rope)
		let length = (code as NSString).length
		for token in engine.highlights(rope: rope, byteRange: 0..<rope.byteCount) {
			let start = max(0, min(token.range.lowerBound, length))
			let end = max(start, min(token.range.upperBound, length))
			guard end > start else { continue }
			output.addAttribute(
				.foregroundColor,
				value: Theme.current.color(for: token.kind),
				range: NSRange(location: start, length: end - start)
			)
		}
		return output
	}

	/// A block is as wide as the column, which it is not by default: a bare
	/// `NSTextBlock` has no width at all, and a paragraph laid out in one comes
	/// out one letter wide — the whole page did, on the first run of this.
	private static func spanTheColumn(_ block: NSTextBlock) {
		block.setValue(100, type: .percentageValueType, for: .width)
	}

	// MARK: - Quotes and lists, which span paragraphs

	/// One block per quote, shared by every paragraph in it, so the bar down
	/// the left edge is one bar. Keyed by the quote component's identity and
	/// emptied at the start of each render.
	private static var quoteBlocks: [Int: NSTextBlock] = [:]

	private static func quoteBlock(of intent: PresentationIntent?) -> NSTextBlock? {
		for component in intent?.components ?? [] {
			guard case .blockQuote = component.kind else { continue }
			if let made = quoteBlocks[component.identity] { return made }
			let block = NSTextBlock()
			spanTheColumn(block)
			block.setBorderColor(Theme.current.separator, for: .minX)
			block.setWidth(type.quoteBar, type: .absoluteValueType, for: .border, edge: .minX)
			block.setWidth(type.quotePadding, type: .absoluteValueType, for: .padding, edge: .minX)
			quoteBlocks[component.identity] = block
			return block
		}
		return nil
	}

	/// The list items whose marker has been written. An item of two paragraphs
	/// is two blocks to the parser, and the second must not get a second bullet.
	private static var markedListItems: Set<Int> = []

	private static func styled(
		text: String,
		run: AttributedString.Runs.Run,
		intent: PresentationIntent?,
		next: PresentationIntent?,
		isBlockStart: Bool
	) -> NSAttributedString {
		var font = bodyFont
		var color = Theme.current.editorText
		let paragraph = bodyParagraph()
		var blocks: [NSTextBlock] = []
		if let quote = quoteBlock(of: intent) {
			blocks.append(quote)
			color = dimText
		}

		var prefix = ""
		var text = text

		// Components run innermost → outermost: a nested item arrives as
		// paragraph, item, list, item, list. A paragraph's depth is the number
		// of lists around it, and its own item is the first one in the array;
		// the list that item belongs to is the component right after it.
		let components = intent?.components ?? []
		let listDepth = components.filter { Self.isList($0.kind) }.count
		if let itemIndex = components.firstIndex(where: { if case .listItem = $0.kind { return true }; return false }),
		   case let .listItem(ordinal) = components[itemIndex].kind {
			// The marker hangs in the margin: the text of every line of the item
			// starts at the indent, and the marker sits before it on a tab stop,
			// so a wrapped line begins under the first word and not under the
			// bullet.
			let indent = type.listIndent * Double(listDepth)
			paragraph.headIndent = indent
			paragraph.firstLineHeadIndent = indent
			paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
			paragraph.paragraphSpacing = Self.isListItem(next) ? type.listItemSpacing : type.paragraphSpacing
			let identity = components[itemIndex].identity
			if isBlockStart, !markedListItems.contains(identity) {
				markedListItems.insert(identity)
				paragraph.firstLineHeadIndent = indent - type.listIndent * 0.75
				var ordered = false
				if itemIndex + 1 < components.count, case .orderedList = components[itemIndex + 1].kind { ordered = true }
				prefix = ordered ? "\(ordinal).\t" : ["•", "◦", "▪"][max(0, listDepth - 1) % 3] + "\t"
			}
		}

		for component in components {
			switch component.kind {
			case let .header(level):
				font = headingFont(level: level)
				color = level >= 6 ? dimText : Theme.current.sidebarHeaderText
				paragraph.lineSpacing = lineSpacing(for: font, height: type.heading(level) * 1.25)
				// More above than below, so a heading belongs to what follows.
				// The paragraph before has already put its own spacing under
				// itself, and this is the rest.
				let above = type.headingSpaceAbove - type.paragraphSpacing
				if level <= 2 {
					// The rule under a title is a block border rather than a drawn
					// line, and the spacing goes on the block: spacing on the
					// paragraph would be laid out inside the block, under the rule.
					let rule = NSTextBlock()
					spanTheColumn(rule)
					rule.setBorderColor(Theme.current.separator, for: .maxY)
					rule.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
					rule.setWidth(type.headingRulePadding, type: .absoluteValueType, for: .padding, edge: .maxY)
					rule.setWidth(above, type: .absoluteValueType, for: .margin, edge: .minY)
					rule.setWidth(type.headingSpaceBelow, type: .absoluteValueType, for: .margin, edge: .maxY)
					blocks.append(rule)
					paragraph.paragraphSpacing = 0
				} else {
					paragraph.paragraphSpacingBefore = above
					paragraph.paragraphSpacing = type.headingSpaceBelow
				}

			case .thematicBreak:
				// A drawn bar, not a string of dashes: a block with a border
				// along its bottom edge in the separator colour, holding a
				// paragraph of nothing set very small. A border and not a
				// background, because a block paints its background over its
				// margins too, and that came out as a band a paragraph tall.
				let bar = NSTextBlock()
				spanTheColumn(bar)
				bar.setBorderColor(Theme.current.separator, for: .maxY)
				bar.setWidth(type.ruleHeight, type: .absoluteValueType, for: .border, edge: .maxY)
				bar.setWidth(type.ruleSpace - type.paragraphSpacing, type: .absoluteValueType, for: .margin, edge: .minY)
				bar.setWidth(type.ruleSpace, type: .absoluteValueType, for: .margin, edge: .maxY)
				blocks.append(bar)
				font = Theme.font(size: max(1, type.ruleHeight * 0.8), weight: .regular, monospaced: false)
				paragraph.lineSpacing = 0
				paragraph.paragraphSpacing = 0
				text = "\u{200B}"

			default:
				break
			}
		}

		if !blocks.isEmpty { paragraph.textBlocks = blocks }

		var attributes: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: color,
			.paragraphStyle: paragraph,
		]

		// Inline styling layered on top of the block style.
		var isInlineCode = false
		if let inline = run.inlinePresentationIntent {
			if inline.contains(.stronglyEmphasized) {
				attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
			}
			if inline.contains(.emphasized) {
				attributes[.font] = NSFontManager.shared.convert(
					attributes[.font] as? NSFont ?? font,
					toHaveTrait: .italicFontMask
				)
			}
			if inline.contains(.code) {
				// At 85 % of whatever it sits in, so code in a heading is heading
				// sized; on a pill the layout manager paints, in the text colour.
				isInlineCode = true
				attributes[.font] = Theme.font(size: font.pointSize * 0.85, weight: .regular, monospaced: true)
				attributes[.abydosInlineCode] = MarkdownPill(
					colour: panelColour,
					radius: type.cornerRadius * 0.75,
					padX: type.pillPaddingX,
					padY: type.pillPaddingY
				)
			}
			if inline.contains(.strikethrough) {
				attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
			}
		}

		if let link = run.link {
			attributes[.link] = link
			attributes[.foregroundColor] = Theme.current.color(for: .link)
			attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
		}

		let output = NSMutableAttributedString(string: prefix + text, attributes: attributes)
		if isInlineCode, output.length > 0 {
			// Room after the last letter, so the next word steps aside for the pill.
			output.addAttribute(.kern, value: type.pillPaddingX, range: NSRange(location: output.length - 1, length: 1))
		}
		return output
	}

	// MARK: - Diagrams

	/// A ```` ```mermaid ```` fence, as the picture it describes.
	///
	/// Most Mermaid in the wild lives in a Markdown file rather than in a `.mmd`,
	/// so this is where most people meet it. What is drawn is drawn by exactly the
	/// machinery the `.mmd` pane uses — one `MermaidRenderer`, one web view, and
	/// the same flattening of a browser's stylesheet into geometry that five
	/// separate faults were found in during 0425. There is no second path, on
	/// purpose: a second path is how a fence would end up with black wedges for
	/// edges again.
	///
	/// Drawing is asynchronous and this is not, so a fence has three states rather
	/// than two. The picture is asked for; if it is not ready the block says so in
	/// one quiet line, and the pane renders again when it arrives.
	private static func renderDiagram(_ fence: MarkdownFence.Drawn) -> NSAttributedString {
		// A block somebody has opened and not written in yet is not an error, and
		// asking Mermaid about it would produce one. It reads as what it is.
		guard Mermaid.hasDiagram(fence.source) else {
			return codeBlock(fence.source + "\n")
		}

		// 0429's rule, unchanged and not restated: the file wins, and the app's
		// theme is the default. A fence has no front matter of its own unless it
		// carries one, so almost every one of them follows the window.
		let stated = Mermaid.statedLook(in: fence.source)
		let theme: DiagramTheme? = stated == nil ? (Theme.current.isLight ? .light : .dark) : nil

		switch MarkdownDiagrams.shared.picture(for: fence.source, theme: theme) {
		case let .drawn(image, paper):
			let output = NSMutableAttributedString(
				attributedString: picture(image, paper: paper)
			)
			// The one thing somebody has to be able to see while looking at a
			// diagram that did not follow the window — the same sentence the
			// `.mmd` pane puts at its foot, for the same reason.
			if let stated {
				output.append(aside(DiagramLook.notice(stated: stated)))
			}
			// And the other thing a drawing cannot say for itself: that it asked
			// to be laid out by an engine this build has not got, and was drawn
			// with Mermaid's own instead without a word from Mermaid.
			if let wanted = Mermaid.statedLayout(in: fence.source) {
				output.append(aside(DiagramLook.layoutNotice(wanted: wanted)))
			}
			return output

		case let .fault(fault):
			// The block as it was written, and the complaint under it. Never a
			// gap: a diagram half way through being typed does not parse, and a
			// preview that answered that with nothing at all would look broken
			// rather than unfinished. The line is counted from the top of the
			// *file*, since that is the number in the editor beside it.
			let output = codeBlock(fence.source + "\n")
			output.append(aside(
				fault.sentence(for: "This diagram", offset: fence.openingLine)
			))
			return output

		case let .trouble(said):
			let output = codeBlock(fence.source + "\n")
			output.append(aside(said))
			return output

		case .none:
			return aside("Drawing this diagram…")
		}
	}

	/// A picture on disk, decoded once per version of the file.
	///
	/// The preview is rendered again on every edit, and decoding a 5k screenshot
	/// on each keystroke would be the cost of typing next to it. Keyed by path
	/// and the file's modification date, so a picture re-taken under the same
	/// name is read again and one that has not changed is not.
	private static var pictures: [String: (modified: Date?, image: NSImage)] = [:]

	private static func picture(at url: URL) -> NSImage? {
		guard url.isFileURL else { return nil }
		let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
		if let cached = pictures[url.path], cached.modified == modified { return cached.image }
		guard let image = NSImage(contentsOf: url) else { return nil }
		pictures[url.path] = (modified, image)
		return image
	}

	/// The drawing itself, as one attachment on a line of its own.
	private static func picture(_ image: NSImage, paper: NSColor) -> NSAttributedString {
		let attachment = NSTextAttachment()
		attachment.attachmentCell = DiagramAttachmentCell(picture: image, paper: paper)

		let paragraph = NSMutableParagraphStyle()
		paragraph.paragraphSpacing = type.paragraphSpacing

		let output = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
		output.append(NSAttributedString(string: "\n"))
		output.addAttribute(
			.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: output.length)
		)
		return output
	}

	/// One quiet line under a block: what is being waited for, or what went wrong.
	private static func aside(_ said: String) -> NSAttributedString {
		let paragraph = bodyParagraph()
		return NSAttributedString(string: said + "\n", attributes: [
			.font: Theme.font(size: type.code, weight: .regular, monospaced: false),
			.foregroundColor: dimText,
			.paragraphStyle: paragraph,
		])
	}

	// MARK: - Tables

	private enum Block {
		case markdown(String)
		case table(String)
	}

	/// Separates GFM pipe tables from the rest of the document.
	///
	/// A table is a run of consecutive lines starting with `|`, where the second
	/// line is a delimiter row (dashes and optional colons).
	private static func splitOutTables(_ markdown: String) -> [Block] {
		let lines = markdown.components(separatedBy: "\n")
		var blocks: [Block] = []
		var current: [String] = []
		var index = 0

		func flush() {
			if !current.isEmpty {
				blocks.append(.markdown(current.joined(separator: "\n")))
				current = []
			}
		}

		while index < lines.count {
			let line = lines[index].trimmingCharacters(in: .whitespaces)
			let next = index + 1 < lines.count ? lines[index + 1].trimmingCharacters(in: .whitespaces) : ""

			let looksLikeTable = line.hasPrefix("|") && MarkdownTable.isDelimiterRow(next)

			guard looksLikeTable else {
				current.append(lines[index])
				index += 1
				continue
			}

			flush()
			var tableLines: [String] = []
			while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
				tableLines.append(lines[index])
				index += 1
			}
			blocks.append(.table(tableLines.joined(separator: "\n")))
		}

		flush()
		return blocks
	}

	/// Renders a pipe table as column-aligned monospace text.
	private static func renderTable(_ text: String, baseURL: URL?) -> NSAttributedString {
		let lines = text.components(separatedBy: "\n")
			.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("|") }
		let rows = lines.map { MarkdownTable.cells(in: $0) }
		guard rows.count >= 2 else {
			return NSAttributedString(string: text + "\n", attributes: [.font: monoFont])
		}

		// Row 1 is the delimiter: it carries alignment rather than content, and
		// until this was read the `---:` in a price column did nothing at all.
		let header = rows[0]
		let alignments = MarkdownTable.alignments(inDelimiterRow: lines[1])
		let body = Array(rows.dropFirst(2))
		let columnCount = rows.map(\.count).max() ?? 0
		guard columnCount > 0 else { return NSAttributedString(string: text + "\n") }

		// A real text table rather than cells padded with spaces. Padding only
		// holds while no line wraps, and in a pane narrower than the widest row
		// every long cell wrapped back to the left margin — which is what turned
		// a three-column table into a paragraph with bars in it. A table block
		// wraps inside its own column and keeps the grid.
		let table = NSTextTable()
		table.numberOfColumns = columnCount
		table.layoutAlgorithm = .automaticLayoutAlgorithm
		table.collapsesBorders = true
		table.hidesEmptyCells = false

		let output = NSMutableAttributedString()
		for (rowIndex, cells) in ([header] + body).enumerated() {
			let isHeader = rowIndex == 0
			for column in 0..<columnCount {
				let cell = column < cells.count ? cells[column] : ""
				output.append(tableCell(
					cell,
					in: table,
					row: rowIndex,
					column: column,
					isHeader: isHeader,
					alignment: column < alignments.count ? alignments[column] : .leading,
					baseURL: baseURL
				))
			}
		}
		output.append(NSAttributedString(string: "\n"))
		return output
	}

	/// One cell, as its own paragraph inside the table's grid.
	private static func tableCell(
		_ text: String,
		in table: NSTextTable,
		row: Int,
		column: Int,
		isHeader: Bool,
		alignment: MarkdownTable.Alignment,
		baseURL: URL?
	) -> NSAttributedString {
		let block = NSTextTableBlock(
			table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1
		)
		block.setBorderColor(Theme.current.separator)
		block.setWidth(1, type: .absoluteValueType, for: .border)
		block.setWidth(type.body * 0.4, type: .absoluteValueType, for: .padding)
		if isHeader {
			block.backgroundColor = Theme.current.selectionInactive.withAlphaComponent(0.35)
		}

		let paragraph = NSMutableParagraphStyle()
		paragraph.textBlocks = [block]
		// Inside a cell, wrapping is the point: a long sentence wraps within its
		// own column instead of running under the one beside it.
		paragraph.lineBreakMode = .byWordWrapping
		// What the delimiter row's colons asked for. The header goes with its
		// column, as it does everywhere else that renders GFM.
		switch alignment {
		case .leading: paragraph.alignment = .left
		case .center: paragraph.alignment = .center
		case .trailing: paragraph.alignment = .right
		}

		// The cell's own markdown — a link in a table is still a link, and it
		// read as `[name](name)` before.
		let rendered = NSMutableAttributedString(
			attributedString: renderBlocks(text, baseURL: baseURL)
		)
		trimTrailingNewlines(rendered)
		if rendered.length == 0 { rendered.append(NSAttributedString(string: " ")) }

		let range = NSRange(location: 0, length: rendered.length)
		rendered.addAttribute(.paragraphStyle, value: paragraph, range: range)
		if isHeader {
			rendered.addAttribute(
				.font,
				value: Theme.font(size: type.body, weight: .semibold, monospaced: false),
				range: range
			)
			rendered.addAttribute(
				.foregroundColor, value: Theme.current.sidebarHeaderText, range: range
			)
		}

		// A newline ends every cell, and the last one in a row ends the row.
		rendered.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: paragraph]))
		return rendered
	}

	/// Blocks come back with the trailing newlines a paragraph needs, which
	/// inside a cell would be blank lines in the grid.
	private static func trimTrailingNewlines(_ text: NSMutableAttributedString) {
		while text.length > 0, text.string.hasSuffix("\n") {
			text.deleteCharacters(in: NSRange(location: text.length - 1, length: 1))
		}
	}
}
