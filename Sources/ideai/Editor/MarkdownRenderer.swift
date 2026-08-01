import AppKit
import IdeaiKit

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
		// prose. They are pulled out first and rendered as aligned monospace.
		for block in splitOutTables(markdown) {
			switch block {
			case let .table(text):
				output.append(renderTable(text))
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

		guard let parsed = try? AttributedString(markdown: markdown, options: options, baseURL: baseURL) else {
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

			let looksLikeTable = line.hasPrefix("|")
				&& next.hasPrefix("|")
				&& next.allSatisfy { "|-: \t".contains($0) }

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
	private static func renderTable(_ text: String) -> NSAttributedString {
		let rows = text.components(separatedBy: "\n").compactMap { line -> [String]? in
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard trimmed.hasPrefix("|") else { return nil }
			// Drop the leading and trailing bar before splitting.
			var body = trimmed
			if body.hasPrefix("|") { body.removeFirst() }
			if body.hasSuffix("|") { body.removeLast() }
			return body.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
		}
		guard rows.count >= 2 else {
			return NSAttributedString(string: text + "\n", attributes: [.font: monoFont])
		}

		// Row 1 is the delimiter; it carries alignment, not content.
		let header = rows[0]
		let body = Array(rows.dropFirst(2))
		let columnCount = rows.map(\.count).max() ?? 0

		var widths = [Int](repeating: 0, count: columnCount)
		for row in ([header] + body) {
			for (column, cell) in row.enumerated() where column < columnCount {
				widths[column] = max(widths[column], cell.count)
			}
		}

		func line(_ cells: [String]) -> String {
			var parts: [String] = []
			for column in 0..<columnCount {
				let cell = column < cells.count ? cells[column] : ""
				parts.append(cell.padding(toLength: widths[column], withPad: " ", startingAt: 0))
			}
			return "  " + parts.joined(separator: "  │  ")
		}

		let paragraph = NSMutableParagraphStyle()
		paragraph.paragraphSpacingBefore = 8
		paragraph.paragraphSpacing = 8

		let output = NSMutableAttributedString()
		output.append(NSAttributedString(string: line(header) + "\n", attributes: [
			.font: NSFont.monospacedSystemFont(ofSize: bodySize - 1, weight: .bold),
			.foregroundColor: Theme.current.sidebarHeaderText,
			.paragraphStyle: paragraph,
		]))

		let rule = "  " + widths.map { String(repeating: "─", count: $0) }.joined(separator: "──┼──")
		output.append(NSAttributedString(string: rule + "\n", attributes: [
			.font: monoFont,
			.foregroundColor: Theme.current.separator,
		]))

		for row in body {
			output.append(NSAttributedString(string: line(row) + "\n", attributes: [
				.font: monoFont,
				.foregroundColor: Theme.current.editorText,
			]))
		}
		output.append(NSAttributedString(string: "\n"))
		return output
	}
}
