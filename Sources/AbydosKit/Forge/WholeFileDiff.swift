import Foundation

/// A file's diff, widened until it is the whole file.
///
/// **This is where reading a review in an editor pays.** A browser shows three
/// lines either side of a change and nothing else; here the file is on disk,
/// there is a language server, and the question a reviewer actually has —
/// *what else is in this function, and who calls it* — is one the surrounding
/// code answers. Three lines of context is a limitation of a web page, not a
/// way anybody wants to read code.
///
/// So the hunks are spliced back into the file they came from: the changed
/// lines exactly as git wrote them, and everything between them as context. The
/// result is a unified diff of one hunk covering the file, which `DiffView`
/// draws with the same colours and the same line numbers as any other.
public enum WholeFileDiff {
	/// Widens one file's patch using that file's text at the head.
	///
	/// - Parameters:
	///   - diff: the file's diff, as `gh pr diff` or `git diff` wrote it.
	///   - contents: the file as it is at the head — the *new* side.
	/// - Returns: a unified diff of the whole file, or nil when it cannot be
	///   built. Nil rather than a guess: a deletion has no new side, a binary
	///   file has no lines, and a patch whose line numbers do not fit the text
	///   handed in is a mismatch worth showing as the ordinary diff rather than
	///   as a confidently wrong whole file.
	public static func expand(diff: String, contents: String) -> String? {
		let patch = GitPatch.parse(diff)
		guard !patch.hunks.isEmpty else { return nil }

		let lines = contents.components(separatedBy: "\n")
		// A file ending in a newline splits with a trailing empty piece, which
		// is not a line of the file.
		let newSide = lines.last == "" ? Array(lines.dropLast()) : lines

		var body: [GitPatch.Line] = []
		// Where in `newSide` the next unwritten line is, counting from one the
		// way a diff does.
		var cursor = 1
		var oldCount = 0
		var newCount = 0

		for hunk in patch.hunks.sorted(by: { $0.newStart < $1.newStart }) {
			guard hunk.newStart >= cursor else { return nil }
			guard hunk.newStart <= newSide.count + 1 else { return nil }

			for index in cursor..<hunk.newStart {
				body.append(GitPatch.Line(kind: .context, text: newSide[index - 1]))
				oldCount += 1
				newCount += 1
			}

			for line in hunk.lines {
				body.append(line)
				switch line.kind {
				case .context:   oldCount += 1; newCount += 1
				case .added:     newCount += 1
				case .removed:   oldCount += 1
				case .noNewline: break
				}
			}

			cursor = hunk.newStart + hunk.lines.reduce(0) {
				$0 + ($1.kind == .removed || $1.kind == .noNewline ? 0 : 1)
			}
		}

		guard cursor <= newSide.count + 1 else { return nil }
		if cursor <= newSide.count {
			for index in cursor...newSide.count {
				body.append(GitPatch.Line(kind: .context, text: newSide[index - 1]))
				oldCount += 1
				newCount += 1
			}
		}

		var text = patch.header
		text.append("@@ -1,\(oldCount) +1,\(newCount) @@")
		text += body.map(\.rendered)
		return text.joined(separator: "\n")
	}
}
