import Foundation

/// How a file indents: one tab per level, or a run of spaces.
///
/// The file's own habit beats the setting — joining a tab-indented file and
/// filling it with spaces is worse than either convention on its own — so the
/// style is read from what the file already does, once, and everything that
/// inserts follows it: ⇥, ⇧⇥, a block indent, and return's auto-indent.
public enum IndentStyle: Equatable, Sendable {
	/// One tab character per level.
	case tabs
	/// A run of spaces per level, and how many.
	case spaces(width: Int)

	/// One level of this style: what ⇥ inserts and a block indent shifts by.
	public var unit: String {
		switch self {
		case .tabs: return "\t"
		case .spaces(let width): return String(repeating: " ", count: max(1, width))
		}
	}

	/// The footer chip's words for this style: *Tabs* or *Spaces: 2*. One
	/// place, because the chip, its tooltip, the driven report and the
	/// spec's scenarios all say the same words.
	public var words: String {
		switch self {
		case .tabs: return "Tabs"
		case .spaces(let width): return "Spaces: \(width)"
		}
	}

	/// Reads a buffer's habit from its head: which of tabs or spaces begins
	/// more of its indented lines — tabs winning a tie, the side the file's
	/// existing lines are mostly on — and, for spaces, the most common run of
	/// leading spaces, a tie going to the narrower, because a continuation
	/// line appears once while the step appears at every level. A file with
	/// no indented lines yet, or none beginning with a space, takes the
	/// fallback width as spaces, which is what return already assumed of a
	/// new file.
	///
	/// Bounded like every look a file is given: the first 200 non-empty lines
	/// say the habit, and no file is read to its end to learn how it indents.
	public static func detect(in sample: String, fallbackWidth: Int) -> IndentStyle {
		var tabs = 0
		var spaces = 0
		var runs: [Int: Int] = [:]
		for line in sample.split(separator: "\n", omittingEmptySubsequences: true).prefix(200) {
			guard let first = line.first else { continue }
			if first == "\t" {
				tabs += 1
			} else if first == " " {
				spaces += 1
				let run = line.prefix(while: { $0 == " " }).count
				runs[run] = (runs[run] ?? 0) + 1
			}
		}
		if tabs == 0, spaces == 0 { return .spaces(width: max(1, fallbackWidth)) }
		if tabs >= spaces { return .tabs }

		var width = max(1, fallbackWidth)
		var widest = 0
		for (run, count) in runs where count > widest || (count == widest && run < width) {
			width = run
			widest = count
		}
		return .spaces(width: max(1, width))
	}

	/// The widths the footer's menu offers beside *Tabs*: the standing 2, 4
	/// and 8, and the style's own width when it is not one of them, because
	/// the width a file was actually written in is not a thing a standing
	/// list should hide. One rule, read by the menu and by the driven report
	/// alike.
	public static func offeredWidths(currentWidth: Int?) -> [Int] {
		var widths: Set<Int> = [2, 4, 8]
		if let currentWidth { widths.insert(currentWidth) }
		return widths.sorted()
	}

	/// Converts a text's indentation from one style to another, level by
	/// level: a level of the source — one leading tab, or the source width in
	/// leading spaces — becomes one level of the target. Only a line's
	/// indentation is converted; a tab after the first non-blank is
	/// alignment, and alignment is a choice rather than a habit, so it is
	/// left alone. A partial level at the end of the indent keeps its spaces,
	/// and a tab-indented file's stray leading spaces are kept as they are
	/// too — the style cannot read an intent into them. Converting to the
	/// style the text already has changes nothing.
	public static func converted(_ text: String, from source: IndentStyle, to target: IndentStyle) -> String {
		guard source != target else { return text }
		// Whether a run of leading spaces means levels at all: in a spaces
		// file it does, `sourceWidth` to a level; in a tabs file it is
		// somebody's hand, passed through untouched.
		let spacesAreLevels: Bool
		let sourceWidth: Int
		if case .spaces(let width) = source {
			spacesAreLevels = true
			sourceWidth = max(1, width)
		} else {
			spacesAreLevels = false
			sourceWidth = 1
		}

		return text.components(separatedBy: "\n").map { line -> String in
			let leading = line.prefix { $0 == " " || $0 == "\t" }
			guard !leading.isEmpty else { return line }

			var out = ""
			var pending = 0
			for character in leading {
				if character == "\t" {
					out += target.unit
				} else if spacesAreLevels {
					pending += 1
					if pending == sourceWidth {
						out += target.unit
						pending = 0
					}
				} else {
					out.append(character)
				}
			}
			// The partial level, kept as spaces rather than rounded either
			// way — an editor that moved content to suit its arithmetic is
			// an editor nobody trusts twice.
			out += String(repeating: " ", count: pending)
			return out + line.dropFirst(leading.count)
		}.joined(separator: "\n")
	}
}