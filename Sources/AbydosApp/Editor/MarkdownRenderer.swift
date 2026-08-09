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
enum MarkdownRenderer {
	static func render(_ markdown: String, baseURL: URL?) -> NSAttributedString {
		let output = NSMutableAttributedString()

		// Foundation's parser does not understand GFM pipe tables — they arrive
		// as ordinary paragraphs with the bars intact, which reads as mangled
		// prose. They are pulled out first and laid out as a real table.
		for block in splitOutTables(markdown) {
			switch block {
			case let .table(text):
				// A table's first cell has to begin a paragraph of its own: a
				// paragraph takes the style of its first character, so a cell
				// appended to an unterminated heading joins that heading instead
				// of opening the grid — which put "file" beside "The diagrams"
				// and shifted every column one to the left.
				if output.length > 0, !output.string.hasSuffix("\n") {
					output.append(NSAttributedString(string: "\n"))
				}
				output.append(renderTable(text, baseURL: baseURL))
			case let .markdown(text):
				output.append(renderBlocks(text, baseURL: baseURL))
			}
		}
		return output
	}

	// MARK: - Fonts and colours

	private static let bodySize: CGFloat = 13.5
	private static var bodyFont: NSFont { .systemFont(ofSize: bodySize) }
	private static var monoFont: NSFont { .monospacedSystemFont(ofSize: bodySize - 1, weight: .regular) }

	private static func headingFont(level: Int) -> NSFont {
		let sizes: [CGFloat] = [24, 20, 17, 15, 14, 13.5]
		let size = sizes[max(0, min(level - 1, sizes.count - 1))]
		return .systemFont(ofSize: size, weight: level <= 2 ? .bold : .semibold)
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

			// A fenced block is highlighted as a whole: a string or a comment
			// can span lines, and colouring one run at a time would end them at
			// every newline.
			if let language = Self.fenceLanguage(of: intent) {
				var text = String(parsed[run.range].characters)
				var next = index + 1
				while next < runs.count,
				      runs[next].presentationIntent?.components.map(\.identity) == blockID {
					text += String(parsed[runs[next].range].characters)
					next += 1
				}
				if previousBlockID != nil { output.append(NSAttributedString(string: "\n")) }
				previousBlockID = blockID
				output.append(highlightedCode(text, languageId: language))
				index = next
				continue
			}

			index += 1
			let text = String(parsed[run.range].characters)

			// A block's marker belongs on its first run only. Inline styling
			// splits a list item into several runs, so applying it per run
			// sprinkles bullets through the middle of sentences.
			let isBlockStart = previousBlockID != blockID
			if previousBlockID != nil, isBlockStart {
				output.append(NSAttributedString(string: "\n"))
			}
			previousBlockID = blockID

			output.append(styled(text: text, run: run, intent: intent, isBlockStart: isBlockStart))
		}

		return output
	}

	/// The language a fenced block claims, when a grammar is loaded for it.
	private static func fenceLanguage(of intent: PresentationIntent?) -> String? {
		for component in intent?.components ?? [] {
			guard case let .codeBlock(hint) = component.kind else { continue }
			guard let hint else { return nil }
			return LanguageRegistry.shared.languageId(forFenceInfo: hint)
		}
		return nil
	}

	/// A code block, coloured by its own grammar.
	private static func highlightedCode(_ text: String, languageId: String) -> NSAttributedString {
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineSpacing = 2
		paragraph.paragraphSpacing = 8
		paragraph.firstLineHeadIndent = 12
		paragraph.headIndent = 12

		let output = NSMutableAttributedString(string: text, attributes: [
			.font: monoFont,
			.foregroundColor: Theme.current.editorText,
			.paragraphStyle: paragraph,
		])

		guard let engine = SyntaxEngine(languageId: languageId) else { return output }
		let rope = Rope(text)
		engine.parse(rope: rope)

		let length = (text as NSString).length
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

	private static func styled(
		text: String,
		run: AttributedString.Runs.Run,
		intent: PresentationIntent?,
		isBlockStart: Bool
	) -> NSAttributedString {
		var font = bodyFont
		var color = Theme.current.editorText
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineSpacing = 2
		paragraph.paragraphSpacing = 8

		var prefix = ""
		var isCodeBlock = false

		// Components run outermost → innermost; the innermost decides appearance.
		for component in intent?.components ?? [] {
			switch component.kind {
			case let .header(level):
				font = headingFont(level: level)
				color = Theme.current.sidebarHeaderText
				paragraph.paragraphSpacingBefore = 14
				paragraph.paragraphSpacing = 6

			case .codeBlock:
				font = monoFont
				color = Theme.current.gitAdded
				isCodeBlock = true
				paragraph.firstLineHeadIndent = 12
				paragraph.headIndent = 12

			case .blockQuote:
				color = Theme.current.gitIgnored
				paragraph.firstLineHeadIndent = 16
				paragraph.headIndent = 16

			case let .listItem(ordinal):
				paragraph.firstLineHeadIndent = 16
				paragraph.headIndent = 32
				if isBlockStart { prefix = "\(ordinal). " }

			case .unorderedList:
				// The bullet is applied on the item, which comes after this.
				prefix = ""

			case .thematicBreak:
				// A rule of em-dashes; drawing a real line needs a custom
				// attachment, which is not worth it for a preview.
				return NSAttributedString(string: "\n––––––––––\n", attributes: [
					.font: bodyFont,
					.foregroundColor: Theme.current.separator,
				])

			default:
				break
			}
		}

		// Unordered items get a bullet; ordered ones already have their number.
		if isBlockStart,
		   let components = intent?.components,
		   components.contains(where: { if case .unorderedList = $0.kind { return true }; return false }),
		   components.contains(where: { if case .listItem = $0.kind { return true }; return false }) {
			prefix = "•  "
		}

		var attributes: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: color,
			.paragraphStyle: paragraph,
		]

		// Inline styling layered on top of the block style.
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
			if inline.contains(.code), !isCodeBlock {
				attributes[.font] = monoFont
				attributes[.foregroundColor] = Theme.current.gitAdded
				attributes[.backgroundColor] = NSColor.white.withAlphaComponent(0.06)
			}
			if inline.contains(.strikethrough) {
				attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
			}
		}

		if let link = run.link {
			attributes[.link] = link
			attributes[.foregroundColor] = Theme.current.gitModified
			attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
		}

		return NSAttributedString(string: prefix + text, attributes: attributes)
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
		block.setWidth(6, type: .absoluteValueType, for: .padding)
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
				value: NSFont.systemFont(ofSize: bodySize, weight: .semibold),
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
