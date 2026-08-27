import Foundation

/// One diff of many files, taken apart into one diff per file.
///
/// A pull request's diff is asked for once — `gh pr diff` — because a change of
/// forty files would otherwise be forty processes, and the file count is the
/// size of somebody else's work rather than anything this code chooses. What the
/// page needs is a file at a time, which is this.
///
/// It is also what a tick is recorded against. `ResultChecklist`'s token for a
/// row is the hash of that file's diff at the head it was read at, so that a
/// rebase which changed nothing keeps its ticks and a push which rewrote one
/// file loses exactly that one — see the `pull-requests` spec.
public enum FileDiffs {
	/// Splits a multi-file diff by its `diff --git` lines.
	///
	/// Keyed by the path on the **right** of the diff — `b/…` — because that is
	/// the path a file has now, and the path every other list here names it by.
	/// A deletion has no right-hand path, so it falls back to the left.
	public static func split(_ diff: String) -> [String: String] {
		var pieces: [String: String] = [:]
		var path: String?
		var lines: [Substring] = []

		func finish() {
			guard let path, !lines.isEmpty else { return }
			pieces[path] = lines.joined(separator: "\n")
		}

		for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
			if line.hasPrefix("diff --git ") {
				finish()
				path = self.path(fromHeader: String(line))
				lines = [line]
				continue
			}
			guard path != nil else { continue }
			lines.append(line)
		}
		finish()
		return pieces
	}

	/// `diff --git a/one/two.txt b/one/two.txt` → `one/two.txt`.
	///
	/// **Split from the middle rather than by spaces.** A path with a space in
	/// it — and there are plenty — makes the line four or more fields, and
	/// taking the last one gives half a filename. What is reliable is the ` b/`
	/// that separates the two halves, and a rename is the case that proves it:
	/// the two paths differ, so the right-hand one has to be found rather than
	/// assumed.
	static func path(fromHeader header: String) -> String? {
		let body = header.dropFirst("diff --git ".count)
		guard let separator = body.range(of: " b/", options: .backwards) else {
			// No right-hand side at all: take whatever follows `a/`.
			guard body.hasPrefix("a/") else { return nil }
			let left = String(body.dropFirst(2)).trimmingCharacters(in: .whitespaces)
			return left.isEmpty ? nil : left
		}
		let right = String(body[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
		if !right.isEmpty { return right }
		let left = String(body[..<separator.lowerBound])
		guard left.hasPrefix("a/") else { return nil }
		return String(left.dropFirst(2))
	}

	/// What a tick on this file was made against.
	///
	/// The diff's own text, hashed. Not the head commit — a rebase moves the
	/// head without changing a single file's diff, and clearing every tick on
	/// every push is how a checklist comes to be ignored. Not a hash of the file
	/// either: a file can differ between base and head for reasons the diff does
	/// not show, and the diff is what was read.
	public static func token(forDiff diff: String) -> String {
		var hash: UInt64 = 0xcbf2_9ce4_8422_2325
		for byte in diff.utf8 {
			hash ^= UInt64(byte)
			hash = hash &* 0x0000_0100_0000_01b3
		}
		return String(hash, radix: 16)
	}
}
