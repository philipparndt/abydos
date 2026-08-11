import Foundation

/// A language server's answer to "where is this used", in the shape the results
/// checklist reads.
///
/// The conversion is the whole reason the usages list and the search results can
/// be one list rather than two. A usage is a path, a line and the text of that
/// line — which is a `SearchMatch` in a `FileSearchResult`, the type
/// `SearchChecklist` already keys its marks on. So nothing about the ticking, the
/// file headings or the undo has to be written a second time for usages; only
/// this function does.
///
/// It lives here rather than in the pane because it is the part with answers that
/// can be wrong — which file order, which line text, what a usage outside the
/// project is called — and a window cannot be asked about any of them.
public enum UsageResults {
	/// Groups locations by file, in path order, reading each file once.
	///
	/// One read per file and not one per usage: a file with forty usages in it
	/// should be opened once. Within a file the usages are put in line order,
	/// because a server answers in whatever order its index happens to hold and a
	/// list somebody works down has to go down the file.
	public static func group(_ locations: [LSPLocation], root: URL?) -> [FileSearchResult] {
		var byFile: [String: [LSPLocation]] = [:]
		for location in locations {
			guard let path = location.url?.path else { continue }
			byFile[path, default: []].append(location)
		}

		var results: [FileSearchResult] = []
		for path in byFile.keys.sorted() {
			let url = URL(fileURLWithPath: path)
			let inFile = (byFile[path] ?? []).sorted { $0.range.start.line < $1.range.start.line }
			let lines = (try? String(contentsOfFile: path, encoding: .utf8))?
				.components(separatedBy: "\n") ?? []

			// Where each line starts, in the UTF-16 units the editor selects with,
			// so a row carries a range that means something rather than a
			// placeholder nothing checks.
			var lineStarts: [Int] = []
			lineStarts.reserveCapacity(lines.count)
			var offset = 0
			for line in lines {
				lineStarts.append(offset)
				offset += line.utf16.count + 1
			}

			var matches: [SearchMatch] = []
			matches.reserveCapacity(inFile.count)
			for location in inFile {
				let index = location.range.start.line
				let text = lines.indices.contains(index) ? lines[index] : ""
				let start = lineStarts.indices.contains(index) ? lineStarts[index] : 0
				let from = start + min(location.range.start.character, text.utf16.count)
				// Only when the usage ends on the line it started on. A range that
				// spans lines is a server being generous about what it points at,
				// and a selection to the same place is better than one to a
				// character offset that means nothing on this line.
				let to = location.range.end.line == index
					? start + min(location.range.end.character, text.utf16.count)
					: from
				matches.append(SearchMatch(
					utf16Range: from..<max(from, to), line: index, lineText: text
				))
			}
			results.append(FileSearchResult(
				url: url, relativePath: relativePath(of: url, under: root), matches: matches
			))
		}
		return results
	}

	/// What a file heading shows.
	///
	/// Relative to the project where it is under it, and the whole path where it
	/// is not: a usage in a dependency outside the tree is worth showing rather
	/// than dropping, and calling it by its last component alone would put two
	/// different `Theme.swift` under headings nobody could tell apart.
	static func relativePath(of url: URL, under root: URL?) -> String {
		guard let root else { return url.path }
		let rootPath = root.standardizedFileURL.path
		let path = url.standardizedFileURL.path
		guard path.hasPrefix(rootPath + "/") else { return path }
		return String(path.dropFirst(rootPath.count + 1))
	}
}
