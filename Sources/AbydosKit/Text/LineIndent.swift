import Foundation

/// Indenting and outdenting whole lines, which is what Tab means when more
/// than one line is selected.
///
/// Tab inserted a tab character wherever the caret was, so selecting a block
/// and pressing it replaced the block with a single tab — the selection gone
/// and the work with it. Every editor treats a multi-line selection as a
/// different gesture, and this is that gesture: shift these lines right, or
/// left, and keep them selected.
public enum LineIndent {
	/// Adds one level to every line.
	///
	/// Every line including the empty ones: a blank line inside an indented
	/// block belongs to the block, and leaving it at column zero is what makes
	/// a diff show a line nobody touched.
	public static func indent(_ text: String, using unit: String) -> String {
		lines(of: text).map { line in
			line.isEmpty ? line : unit + line
		}.joined(separator: "\n")
	}

	/// Takes one level off every line that has one.
	///
	/// One tab, or up to `tabWidth` spaces — a file indented with spaces and a
	/// file indented with tabs both outdent by what looks like one level, which
	/// is what somebody pressing ⇧Tab means. A line with no indentation left is
	/// left alone rather than pulled into the line above.
	public static func outdent(_ text: String, tabWidth: Int) -> String {
		let width = max(1, tabWidth)
		return lines(of: text).map { line -> String in
			guard let first = line.first else { return line }
			if first == "\t" { return String(line.dropFirst()) }

			var removed = 0
			var index = line.startIndex
			while index < line.endIndex, line[index] == " ", removed < width {
				index = line.index(after: index)
				removed += 1
			}
			return String(line[index...])
		}.joined(separator: "\n")
	}

	/// How much the first line grew or shrank, so a caret sitting in it can be
	/// moved by the same amount rather than jumping to the start.
	public static func firstLineShift(from before: String, to after: String) -> Int {
		let old = lines(of: before).first ?? ""
		let new = lines(of: after).first ?? ""
		return new.utf16.count - old.utf16.count
	}

	/// Splitting that keeps a trailing empty line, which `split` drops — a
	/// selection ending at a newline covers the line after it, and dropping it
	/// would delete that line's break.
	static func lines(of text: String) -> [String] {
		text.components(separatedBy: "\n")
	}
}
