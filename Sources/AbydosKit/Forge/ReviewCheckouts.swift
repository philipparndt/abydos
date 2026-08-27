import Foundation

/// Which checkouts were made to read a pull request.
///
/// **The list of checkouts is a list of places somebody chose to work.** A
/// checkout made to read somebody else's branch is a different kind of thing:
/// it is temporary, it belongs to a review rather than to a piece of work, and
/// it will accumulate — a repository whose reviewer opens three pull requests a
/// day otherwise grows a checkout a day, each named after a stranger's branch,
/// and the menu that was ordered, capped and honest becomes a list nobody
/// reads. Saying which ones those are is what makes them collectable.
///
/// **The mark is this program's opinion about a directory, not a fact about the
/// repository.** Writing it into `.git` would be writing somebody else's file:
/// git has no notion of a worktree belonging to anything, every other tool
/// reading that repository would have to ignore it, and a `git worktree remove`
/// from a terminal would leave the note behind. It lives with the project's own
/// state instead — in memory for the window, and in `ProjectSession` so that
/// tomorrow's window knows too.
public final class ReviewCheckouts: @unchecked Sendable {
	/// The one every pane asks. A window's worth of state that four unrelated
	/// views need to agree about, which is what `Settings.shared` is too.
	public static let shared = ReviewCheckouts()

	private let lock = NSLock()
	/// Standardised path → the pull request it was made for.
	private var marks: [String: Int] = [:]

	public init() {}

	/// Marks a directory as a pull request's.
	public func mark(_ path: URL, as number: Int) {
		lock.lock()
		defer { lock.unlock() }
		marks[Self.key(path)] = number
	}

	/// Forgets one, as removing the checkout does.
	public func forget(_ path: URL) {
		lock.lock()
		defer { lock.unlock() }
		marks.removeValue(forKey: Self.key(path))
	}

	/// Which pull request this checkout was made for, if it was made for one.
	public func number(of path: URL) -> Int? {
		lock.lock()
		defer { lock.unlock() }
		return marks[Self.key(path)]
	}

	/// Everything known, for writing beside the project.
	public var remembered: [String: Int] {
		lock.lock()
		defer { lock.unlock() }
		return marks
	}

	/// Puts back what a project remembered, keeping anything already known.
	public func restore(_ remembered: [String: Int]) {
		lock.lock()
		defer { lock.unlock() }
		for (path, number) in remembered where marks[path] == nil {
			marks[path] = number
		}
	}

	/// Forgets everything, for a test that should not see another one's marks.
	public func forgetAllForTesting() {
		lock.lock()
		defer { lock.unlock() }
		marks = [:]
	}

	private static func key(_ path: URL) -> String {
		path.standardizedFileURL.resolvingSymlinksInPath().path
	}
}
