import Foundation

/// A unified diff, parsed far enough to stage parts of it.
///
/// Staging a hunk or a few lines means handing git a *new* patch containing
/// only what was chosen. That patch has to be internally consistent — its hunk
/// headers must count the lines it actually carries — or `git apply` rejects
/// it, so the counts are recomputed rather than copied.
public struct GitPatch: Equatable, Sendable {
	/// One line of a diff, tagged by what it does.
	public struct Line: Equatable, Sendable {
		public enum Kind: Equatable, Sendable {
			case context
			case added
			case removed
			/// "\ No newline at end of file" — belongs to the line before it.
			case noNewline
		}

		public let kind: Kind
		/// The text without the leading +/-/space marker.
		public let text: String

		public init(kind: Kind, text: String) {
			self.kind = kind
			self.text = text
		}

		/// Whether this line can be selected for staging.
		public var isSelectable: Bool { kind == .added || kind == .removed }

		/// The +/-/space a unified diff puts at the start of the line.
		public var marker: String {
			switch kind {
			case .context:   return " "
			case .added:     return "+"
			case .removed:   return "-"
			case .noNewline: return "\\"
			}
		}

		var rendered: String { marker + text }
	}

	/// One @@ block.
	public struct Hunk: Equatable, Sendable {
		public var oldStart: Int
		public var newStart: Int
		/// Text after the closing @@, which git carries for context.
		public var heading: String
		public var lines: [Line]

		public init(oldStart: Int, newStart: Int, heading: String, lines: [Line]) {
			self.oldStart = oldStart
			self.newStart = newStart
			self.heading = heading
			self.lines = lines
		}

		public var hasChanges: Bool { lines.contains { $0.isSelectable } }
	}

	/// Everything before the first @@: the `diff --git`, mode and ---/+++ lines.
	public var header: [String]
	public var hunks: [Hunk]

	public init(header: [String] = [], hunks: [Hunk] = []) {
		self.header = header
		self.hunks = hunks
	}

	public var isEmpty: Bool { hunks.allSatisfy { !$0.hasChanges } }

	// MARK: - Parsing

	public static func parse(_ diff: String) -> GitPatch {
		var patch = GitPatch()
		var current: Hunk?

		// `separatedBy` rather than `split`: a diff can legitimately contain
		// blank lines, and dropping them would shift every line index.
		//
		// The final newline is removed first, though. Splitting on it leaves a
		// trailing empty component, which would otherwise be read as a context
		// line — inflating both hunk counts by one and producing a patch git
		// refuses to apply.
		var body = diff
		if body.hasSuffix("\n") { body.removeLast() }

		for line in body.components(separatedBy: "\n") {
			if line.hasPrefix("@@") {
				if let hunk = current { patch.hunks.append(hunk) }
				current = parseHunkHeader(line)
				continue
			}

			guard var hunk = current else {
				// Trailing empty component from the final newline is not header.
				if !line.isEmpty { patch.header.append(line) }
				continue
			}

			guard let marker = line.first else {
				// An empty line inside a hunk is a context line whose content is
				// empty and whose marker git dropped — some tools produce these.
				hunk.lines.append(Line(kind: .context, text: ""))
				current = hunk
				continue
			}

			let text = String(line.dropFirst())
			switch marker {
			case "+": hunk.lines.append(Line(kind: .added, text: text))
			case "-": hunk.lines.append(Line(kind: .removed, text: text))
			case " ": hunk.lines.append(Line(kind: .context, text: text))
			case "\\": hunk.lines.append(Line(kind: .noNewline, text: text))
			default:
				// Anything else ends the hunk: the next file's header.
				patch.hunks.append(hunk)
				current = nil
				patch.header.append(line)
				continue
			}
			current = hunk
		}

		if let hunk = current { patch.hunks.append(hunk) }
		return patch
	}

	private static func parseHunkHeader(_ line: String) -> Hunk? {
		// @@ -oldStart,oldCount +newStart,newCount @@ heading
		let parts = line.components(separatedBy: "@@")
		guard parts.count >= 2 else { return nil }

		let ranges = parts[1].trimmingCharacters(in: .whitespaces)
			.components(separatedBy: " ")
			.filter { !$0.isEmpty }
		guard ranges.count >= 2 else { return nil }

		func start(_ token: String) -> Int {
			let digits = token.dropFirst()          // Drop the - or +.
			return Int(digits.components(separatedBy: ",").first ?? "") ?? 1
		}

		let heading = parts.count > 2
			? parts[2...].joined(separator: "@@").trimmingCharacters(in: .whitespaces)
			: ""

		return Hunk(
			oldStart: start(ranges[0]),
			newStart: start(ranges[1]),
			heading: heading,
			lines: []
		)
	}

	// MARK: - Selecting

	/// Index of every selectable line, numbered across the whole patch.
	///
	/// A single flat numbering so the UI can hold a selection without knowing
	/// how the lines are grouped into hunks.
	public func selectableIndices() -> [Int] {
		var result: [Int] = []
		var index = 0
		for hunk in hunks {
			for line in hunk.lines {
				if line.isSelectable { result.append(index) }
				index += 1
			}
		}
		return result
	}

	/// Every line index belonging to a hunk, for "stage this hunk".
	public func indices(inHunk hunkIndex: Int) -> [Int] {
		var index = 0
		for (position, hunk) in hunks.enumerated() {
			if position == hunkIndex {
				return (index..<(index + hunk.lines.count)).filter { offset in
					hunk.lines[offset - index].isSelectable
				}
			}
			index += hunk.lines.count
		}
		return []
	}

	// MARK: - Building

	/// A patch containing only `selected`, ready for `git apply --cached`.
	///
	/// Returns nil when nothing was selected — applying an empty patch is an
	/// error, not a no-op.
	///
	/// Unselected lines are not simply dropped, and which way they go depends on
	/// which side the patch has to match.
	///
	/// Applying forward, the patch's *old* side must match what is in the index,
	/// so an unselected addition never happened and goes, while an unselected
	/// deletion means the line stays and becomes context.
	///
	/// Applying in reverse — unstaging — the patch's *new* side must match the
	/// index instead, so it is the other way round: an unselected addition is
	/// already in the index and has to be carried as context, and an unselected
	/// deletion is not in the index at all and goes. Getting either backwards
	/// produces a patch git refuses, or worse, one that applies and stages
	/// something nobody chose.
	public func patch(selecting selected: Set<Int>, reverse: Bool = false) -> String? {
		guard !selected.isEmpty else { return nil }

		var output = header
		var index = 0
		var emitted = false

		for hunk in hunks {
			var lines: [Line] = []
			var oldCount = 0
			var newCount = 0
			var hunkHasChange = false

			for line in hunk.lines {
				defer { index += 1 }

				switch line.kind {
				case .context:
					lines.append(line)
					oldCount += 1
					newCount += 1

				case .noNewline:
					lines.append(line)

				case .added:
					if selected.contains(index) {
						lines.append(line)
						newCount += 1
						hunkHasChange = true
					} else if reverse {
						// Already in the index and staying there, so it has to be
						// on both sides or the reverse apply will not match.
						lines.append(Line(kind: .context, text: line.text))
						oldCount += 1
						newCount += 1
					}
					// Forward: as far as this patch goes, it was never added.

				case .removed:
					if selected.contains(index) {
						lines.append(line)
						oldCount += 1
						hunkHasChange = true
					} else if !reverse {
						// Kept, so it is context on both sides.
						lines.append(Line(kind: .context, text: line.text))
						oldCount += 1
						newCount += 1
					}
					// Reverse: not in the index, so it appears on neither side.
				}
			}

			guard hunkHasChange else { continue }
			emitted = true

			// Reversing keeps every addition — selected or as context — so the
			// post-image side is unchanged from the original diff and its
			// numbering still holds. Forward, additions have been dropped, so
			// the post-image start has to follow what was actually emitted.
			let newStart = reverse
				? hunk.newStart
				: hunk.newStart(after: output, fallback: hunk.newStart)
			let heading = hunk.heading.isEmpty ? "" : " \(hunk.heading)"
			output.append("@@ -\(hunk.oldStart),\(oldCount) +\(newStart),\(newCount) @@\(heading)")
			output.append(contentsOf: lines.map(\.rendered))
		}

		guard emitted else { return nil }
		return output.joined(separator: "\n") + "\n"
	}
}

private extension GitPatch.Hunk {
	/// Where this hunk lands on the post-image side.
	///
	/// Recomputed from what has already been written rather than reused from
	/// the original diff: dropping an addition earlier in the file shifts every
	/// later hunk, and a stale number makes `git apply` reject the patch.
	func newStart(after emitted: [String], fallback: Int) -> Int {
		var offset = 0
		for line in emitted where line.hasPrefix("@@") {
			guard let counts = Self.counts(inHeader: line) else { continue }
			offset += counts.new - counts.old
		}
		return oldStart + offset
	}

	static func counts(inHeader line: String) -> (old: Int, new: Int)? {
		let parts = line.components(separatedBy: "@@")
		guard parts.count >= 2 else { return nil }
		let ranges = parts[1].trimmingCharacters(in: .whitespaces)
			.components(separatedBy: " ")
			.filter { !$0.isEmpty }
		guard ranges.count >= 2 else { return nil }

		func count(_ token: String) -> Int {
			let pieces = token.dropFirst().components(separatedBy: ",")
			return pieces.count > 1 ? (Int(pieces[1]) ?? 1) : 1
		}
		return (count(ranges[0]), count(ranges[1]))
	}
}

public extension GitWorkingCopy {
	/// Applies a patch to the index only, leaving the work tree alone.
	///
	/// `--cached` is what makes this staging rather than editing: the work tree
	/// still holds every change, and only the chosen parts move into the index.
	@discardableResult
	static func applyToIndex(
		patch: String,
		reverse: Bool,
		in root: URL
	) async -> GitRepository.ProcessResult {
		// No --unidiff-zero: that relaxes checks for diffs generated with zero
		// context, and applying a normal patch under it can land in the wrong
		// place. --recount lets git trust the line content over the counts,
		// which is the forgiving direction rather than the dangerous one.
		var arguments = ["apply", "--cached", "--recount", "--whitespace=nowarn"]
		if reverse { arguments.append("--reverse") }
		arguments.append("-")

		return await GitRepository.run(arguments, in: root, input: Data(patch.utf8))
	}

	/// Stages the selected lines of a file's unstaged diff.
	@discardableResult
	static func stage(
		lines selected: Set<Int>,
		ofDiff diff: String,
		in root: URL
	) async -> GitRepository.ProcessResult {
		guard let patch = GitPatch.parse(diff).patch(selecting: selected) else {
			return GitRepository.ProcessResult(stdout: "", stderr: "Nothing selected.", exitCode: 1)
		}
		return await applyToIndex(patch: patch, reverse: false, in: root)
	}

	/// Unstages the selected lines of a file's staged diff.
	@discardableResult
	static func unstage(
		lines selected: Set<Int>,
		ofDiff diff: String,
		in root: URL
	) async -> GitRepository.ProcessResult {
		guard let patch = GitPatch.parse(diff).patch(selecting: selected, reverse: true) else {
			return GitRepository.ProcessResult(stdout: "", stderr: "Nothing selected.", exitCode: 1)
		}
		return await applyToIndex(patch: patch, reverse: true, in: root)
	}
}
