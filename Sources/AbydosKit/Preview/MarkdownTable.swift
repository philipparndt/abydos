import Foundation

/// GFM pipe tables, as text.
///
/// Foundation's markdown parser does not understand them at all — a table
/// arrives back as a paragraph with bars in it — so the preview cuts them out
/// and lays them out itself. The cutting is string work with right answers, and
/// it lives here rather than beside the renderer so it can be tested without a
/// window.
public enum MarkdownTable {
	/// Where a column's text sits in the width the column is given.
	public enum Alignment: Sendable, Equatable {
		case leading
		case center
		case trailing
	}

	/// True when a line is the row of dashes under a table's header.
	///
	/// It is what tells a table from a paragraph that happens to begin with a
	/// bar, so it wants at least one dash: `| | |` is not a delimiter row.
	public static func isDelimiterRow(_ line: String) -> Bool {
		let trimmed = line.trimmingCharacters(in: .whitespaces)
		guard trimmed.hasPrefix("|"), trimmed.contains("-") else { return false }
		return trimmed.allSatisfy { "|-: \t".contains($0) }
	}

	/// A row's cells, split on the bars that are not escaped.
	///
	/// `\|` is a pipe somebody wants to *see*. GFM says so, and it is the one
	/// place where a table's own syntax and a cell's content collide: without
	/// this a cell containing a bar becomes two cells, every column after it
	/// slides one to the right, and the table grows a column that nothing is in.
	///
	/// The backslash is kept rather than removed, because what comes back is
	/// parsed as markdown next and `\|` is how a pipe stays a pipe there too.
	public static func cells(in row: String) -> [String] {
		let trimmed = row.trimmingCharacters(in: .whitespaces)
		guard trimmed.hasPrefix("|") else { return [] }

		var cells: [String] = []
		var current = ""
		var escaped = false
		for character in trimmed.dropFirst() {
			if escaped {
				current.append(character)
				escaped = false
			} else if character == "\\" {
				current.append(character)
				escaped = true
			} else if character == "|" {
				cells.append(current.trimmingCharacters(in: .whitespaces))
				current = ""
			} else {
				current.append(character)
			}
		}
		// A row normally ends with a bar, which closes the last cell rather than
		// opening an empty one; anything after the last bar is a cell of its own.
		let tail = current.trimmingCharacters(in: .whitespaces)
		if !tail.isEmpty { cells.append(tail) }
		return cells
	}

	/// What each column's colons in the delimiter row ask for.
	///
	/// `:---` and a bare `---` are both leading — GFM has no way to say "the
	/// default" separately, and the default is leading.
	public static func alignments(inDelimiterRow row: String) -> [Alignment] {
		cells(in: row).map { cell in
			switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
			case (true, true): return .center
			case (false, true): return .trailing
			default: return .leading
			}
		}
	}
}
