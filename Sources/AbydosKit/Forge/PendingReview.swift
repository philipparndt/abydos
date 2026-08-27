import Foundation

/// A review being written: the remarks so far, and what has not been said yet.
///
/// **One submission and not one comment at a time.** That is how GitHub models
/// it and how a reviewer thinks: a review is a set of remarks and a verdict, not
/// a series of interruptions to the author. Somebody reading forty files leaves
/// eleven remarks; the author should get one notification with eleven remarks in
/// it, and should get it when the reviewer has finished thinking.
///
/// **The head travels with it.** The remarks were written against the file as it
/// was when the page was opened, and if the author has pushed since then the
/// line numbers mean something else. That is said before anything is sent —
/// see `headHasMoved`.
public struct PendingReview: Equatable, Sendable {
	/// The commit the page was read at, which every remark is positioned
	/// against.
	public var head: String?
	/// What to say about the change as a whole.
	public var body: String
	/// The remarks, in the order they were written.
	public private(set) var comments: [PendingComment]

	public init(head: String? = nil, body: String = "", comments: [PendingComment] = []) {
		self.head = head
		self.body = body
		self.comments = comments
	}

	public var isEmpty: Bool { comments.isEmpty && body.isEmpty }

	/// Adds a remark, replacing anything already written over those lines.
	///
	/// Replacing rather than appending: leaving two comments on one line by
	/// writing twice is not something anybody means to do, and the second is
	/// what they decided to say. A range replaces every remark it covers, for
	/// the same reason — a remark about lines 10 to 20 is about the one on 14.
	public mutating func write(_ comment: PendingComment) {
		comments.removeAll {
			$0.path == comment.path
				&& (comment.covers($0.line) || $0.covers(comment.line))
		}
		guard !comment.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
		comments.append(comment)
	}

	/// Takes a remark back.
	public mutating func erase(on path: String, line: Int) {
		comments.removeAll { $0.path == path && $0.covers(line) }
	}

	/// What was written on a line, if anything was — including a remark whose
	/// range covers it.
	public func comment(on path: String, line: Int) -> PendingComment? {
		comments.first { $0.path == path && $0.covers(line) }
	}

	/// Everything written on one file, by the line each remark is anchored to.
	public func comments(on path: String) -> [Int: PendingComment] {
		Dictionary(
			comments.filter { $0.path == path }.map { ($0.line, $0) },
			uniquingKeysWith: { _, second in second }
		)
	}

	public mutating func clear() {
		comments = []
		body = ""
	}

	/// Whether the pull request has moved since this review was begun, and what
	/// to say about it.
	///
	/// **The failure this guards against is a review that lands on the wrong
	/// lines.** A remark written against line 40 of a file the author has since
	/// rewritten is a remark about somebody else's code, sent in the reviewer's
	/// name. Nothing is sent when this answers something.
	public static func headHasMoved(from written: String?, to current: String?) -> String? {
		guard let written, let current, written != current else { return nil }
		return "This review was written at \(written.prefix(8)) and the pull request is now at "
			+ "\(current.prefix(8)). Read it again before sending: the lines the remarks are on "
			+ "may not be the lines they were written on."
	}
}
