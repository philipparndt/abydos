import Foundation

/// Syntax highlighting for a diff.
///
/// A diff is not a program: it is two programs interleaved, each with holes in
/// it where the other one is. Handing that to a parser gets nothing useful, so
/// each side is reconstructed first — context plus removals is the file as it
/// was, context plus additions is the file as it will be — and each is parsed
/// on its own. Every line then takes its colours from the side it belongs to,
/// and context lines, which are in both, take them from the new one.
///
/// The reconstruction is only as complete as the diff: hunks are stitched
/// together with the unchanged thousands of lines between them missing. A
/// parser handed that will misread some of it, which is why this is highlighting
/// and not analysis. Tree-sitter recovers from the seams well enough that the
/// result is worth having — a diff of a function reads as code rather than as
/// two colours of text.
public enum DiffHighlighter {
	/// Tokens for each line of a patch, keyed by the patch's flat line index.
	///
	/// Ranges are UTF-16 offsets within that line's own text, so a view can draw
	/// a line without knowing where it sat in the reconstruction.
	public static func highlight(_ patch: GitPatch, languageId: String) -> [Int: [HighlightToken]] {
		guard let engine = SyntaxEngine(languageId: languageId), engine.hasHighlightQuery else { return [:] }

		var result: [Int: [HighlightToken]] = [:]
		// New side first, so context lines end up with the old side's tokens
		// only where the new side had nothing to say about them.
		for side in [Side.new, .old] {
			let (text, lineIndices) = reconstruct(patch, side: side)
			guard !text.isEmpty else { continue }
			for (index, tokens) in tokens(in: text, lineIndices: lineIndices, engine: engine) {
				if result[index] == nil { result[index] = tokens }
			}
		}
		return result
	}

	private enum Side {
		case old, new

		func includes(_ kind: GitPatch.Line.Kind) -> Bool {
			switch kind {
			case .context: return true
			case .added: return self == .new
			case .removed: return self == .old
			case .noNewline: return false
			}
		}
	}

	/// One side of the patch as text, with each of its lines' patch index.
	private static func reconstruct(_ patch: GitPatch, side: Side) -> (String, [Int]) {
		var text = ""
		var lineIndices: [Int] = []

		var index = 0
		for hunk in patch.hunks {
			for line in hunk.lines {
				defer { index += 1 }
				guard side.includes(line.kind) else { continue }
				text += line.text
				text += "\n"
				lineIndices.append(index)
			}
		}
		return (text, lineIndices)
	}

	/// Parses one side and cuts its tokens up by line.
	///
	/// Offsets in and out are UTF-16, which is what the engine deals in and what
	/// an attributed string is indexed by; nothing here needs to know how many
	/// bytes a character took.
	private static func tokens(
		in text: String,
		lineIndices: [Int],
		engine: SyntaxEngine
	) -> [Int: [HighlightToken]] {
		let rope = Rope(text)
		engine.parse(rope: rope)
		let all = engine.highlights(rope: rope, byteRange: 0..<rope.byteCount)
		guard !all.isEmpty else { return [:] }

		// Where each line starts, so a token can be made relative to the line
		// it lands on.
		var lineStarts = [0]
		var offset = 0
		for unit in text.utf16 {
			offset += 1
			if unit == UInt16(UInt8(ascii: "\n")) { lineStarts.append(offset) }
		}
		let total = offset

		var result: [Int: [HighlightToken]] = [:]
		var line = 0
		for token in all.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
			// Walk forward to the line this token starts on; tokens arrive in
			// order, so each line is visited at most once.
			while line + 1 < lineStarts.count, lineStarts[line + 1] <= token.range.lowerBound {
				line += 1
			}

			// A token can cross line breaks — a block comment, a multi-line
			// string — and each line it covers gets its own share of it.
			var covered = line
			while covered < lineIndices.count, lineStarts[covered] < token.range.upperBound {
				let start = lineStarts[covered]
				let end = covered + 1 < lineStarts.count ? lineStarts[covered + 1] - 1 : total
				let lower = max(token.range.lowerBound, start) - start
				let upper = min(token.range.upperBound, end) - start
				if upper > lower {
					result[lineIndices[covered], default: []].append(
						HighlightToken(range: lower..<upper, kind: token.kind)
					)
				}
				covered += 1
			}
		}
		return result
	}
}
