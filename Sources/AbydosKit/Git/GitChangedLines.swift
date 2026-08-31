import Foundation

/// Which lines of a file differ from HEAD, read off a parsed diff — the model
/// behind the editor gutter's change marks.
///
/// Parses nothing itself: it walks a `GitPatch`, whose hunks already carry the
/// new-file line numbers, and classifies. A run of removed lines immediately
/// followed by a run of added lines is a *modification* of the added lines —
/// what every other editor calls "changed" — because calling every edit an
/// addition would paint the whole gutter as new code the moment a line is
/// touched. Removals nothing replaced leave a mark *after* the line that
/// precedes them; 0 means lines were deleted above the first line.
///
/// Line numbers are 1-based, as git writes them. The deletion arithmetic
/// assumes the diff was made with context lines (git's default): a `-U0`
/// diff numbers a zero-length new range by the line *before* it, which this
/// walk does not correct for — and nothing in this app asks for one.
public struct GitChangedLines: Equatable, Sendable {
	public enum Mark: Equatable, Sendable {
		case added
		case modified
	}

	/// New-file line number → its mark.
	public private(set) var marks: [Int: Mark]
	/// New-file line numbers after which lines were deleted.
	public private(set) var deletedAfter: Set<Int>

	public var isEmpty: Bool { marks.isEmpty && deletedAfter.isEmpty }

	public init(marks: [Int: Mark] = [:], deletedAfter: Set<Int> = []) {
		self.marks = marks
		self.deletedAfter = deletedAfter
	}

	public static func read(_ patch: GitPatch) -> GitChangedLines {
		var marks: [Int: Mark] = [:]
		var deletedAfter: Set<Int> = []

		for hunk in patch.hunks {
			var newLine = hunk.newStart
			// How many removals are waiting for the additions that would make
			// them a modification, and whether additions came. Flushed — as a
			// deletion mark after the last emitted line — when context or the
			// hunk's end says nothing replaced them.
			var pendingRemovals = 0
			var replaced = false

			func flushRemovals() {
				if pendingRemovals > 0, !replaced {
					deletedAfter.insert(max(0, newLine - 1))
				}
				pendingRemovals = 0
				replaced = false
			}

			for line in hunk.lines {
				switch line.kind {
				case .context:
					flushRemovals()
					newLine += 1
				case .removed:
					// A removal after additions starts a new run; the previous
					// one was fully replaced and flushes to nothing.
					if replaced { flushRemovals() }
					pendingRemovals += 1
				case .added:
					if pendingRemovals > 0 { replaced = true }
					marks[newLine] = pendingRemovals > 0 ? .modified : .added
					newLine += 1
				case .noNewline:
					break
				}
			}
			flushRemovals()
		}
		return GitChangedLines(marks: marks, deletedAfter: deletedAfter)
	}
}
